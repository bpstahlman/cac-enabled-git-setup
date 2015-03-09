#! /bin/bash
VERSION=0.9
# Starting cwd is base of operations.
# TODO: Check to be sure it seems to contain the package.
Basedir=$PWD
# Make sure we have an unmodified git we can use to clone source repos.
Sys_git=/usr/bin/git
# This will be detected and set in detect_cac_card.
# Possible TODO: This can also be set by option now. Perhaps put in Opts[]
Card_id=
# Facilitate skipping install step when --no-install specified
Make_install="make install"

declare -i Step_idx=0
# Container for steps specified with --skip-step
declare -A Skip_steps=()
# Container for steps specified with --only-steps
declare -A Only_steps=()
# These are tied to the --start-step / --end-step options
Start_step=
End_step=
# Rules:
# --start-step and/or --end-step puts us in range mode
# --only-step puts us in only mode
# max 1 mode transition permitted
Step_mode=normal # normal | range | only

# Note: A missing boolean option is considered unset.
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

# TODO: Consider making this an on_err (using ERR signal instead of EXIT).
on_exit() {
	if (($? == 0)); then
		log --ts "Success! You may need to open a new terminal before changes take effect."
	else
		cat <<-eof >&2
		Setup aborted with error! Check stdout for details.
		After resolving any issues, you can resume setup at the failed step with the
		following option: --start-step ${Steps[$Step_idx]}"
		eof
	fi
	cd "$Basedir"
}

# Run all steps not excluded by options.
run() {
	local started=no
	if [[ $Step_mode == normal || ($Step_mode == range && -z $Start_step) ]]; then
		started=yes
	fi
	for step in "${Steps[@]}"; do
		local skip=no
		# Process started and skip logic.
		if [[ $Step_mode == only ]]; then
			if [[ -z ${Only_steps[$step]} ]]; then
				skip=yes
			fi
		else # normal | range
			if [[ $started == no && $step == $Start_step ]]; then
				started=yes
			fi
			if [[ $started == no || -n ${Skip_steps[$step]} ]]; then
				skip=yes
			fi
		fi
		# If we're not skipping...
		if [[ $skip == no ]]; then
			log --ts "Starting step #$((Step_idx + 1)): $step"
			${Opts[no-execute]:+echo Simulating step} $step
			log --ts "Finished step #$((Step_idx + 1)): $step"
		fi
		# Check for termination condition.
		if [[ $Step_mode == range && -n $End_step && $step == $End_step ]]; then
			log "Exiting after specified end step: $End_step"
			return 0
		fi
		((++Step_idx))
	done
}

# TODO: Colorize?
log() {
	if [[ $1 == --ts ]]; then
		ts="$(date +%T): "
		shift
	fi
	echo >&2 "$ts$@" 
}
# Display usage message on stderr
usage() {
	# TODO: Path or not?
	local prog=$(basename $0)
	cat >&2 <<-eof
		Usage: $prog [OPTION]...
		Try '$prog --help' for more information.
	eof
}
# Display help on stdout
show_help() {
	local prog=$(basename $0)
	# TODO: Finish converting this...
	cat <<-eof
	Usage: $prog [OPTION]...
	Build a DOD-aware, CAC-enabled Git.

	  -s, --start-step=STEP           start with STEP         
	      --skip-steps=STEP[,STEP]... skip specified step(s)
	      --only-steps=STEP[,STEP]... run *only* specified step(s)
	      --end-step=STEP             end with STEP
	      --card-id=XX                2-digit smart card id
	                                  Note: Can be detected by script if CAC card
	                                  is inserted.
	      --ca-bundle-dir=DIR         where to put generated ca-bundle
	                                  Default: /usr/ssl/certs
	      --ca-bundle-name=NAME       basename for generated ca-bundle
	                                  Default: ca-bundle-plus-dod-root
	      --openssl-conf=PATH         full path for generated openssl conf file
	                                  CAVEAT: Directory must exist.
	                                  Default: /usr/ssl/pkcs11-openssl.cnf
	      --skip-cygwin-install       only if you've already installed the cygwin
	                                  package prerequisites yourself
	      --use-cygwin64              install cygwin 64-bit packages - !UNTESTED!
	      --no-install                builds without installing
	      --no-execute                a sort of "dry run" - steps not executed
	      --list-steps                list the steps (with short desc) and exit
	      --help                      display this help and exit
	      --version                   output version information and exit

	Examples:
	  $prog --ca-bundle-dir=~/my-certs --openssl-conf=~/my-conf/openssl.conf
	  $prog --skip-cygwin-install
	  $prog --start-step create_certs

	Prerequisites: (Before running...)
	  This script assumes you have the default Cygwin "Base" package installed.
	  It also assumes a working \`wget' in your path (may be obtained from the
	  Cygwin "Web" package).

	Running the script:
	  1. Open the default Cygwin shell (runs an instance of Bash).
	  2. Create an empty directory anywhere you like.
	  3. cd to the directory created in step 2, and run this script.

	  Note: The Cygwin terminal's buffer is probably not sufficiently large to
	  hold all of the output generated by the script. If you wish to monitor the
	  script's progress real-time, but capture all output in a logfile, you could
 	  do something like this...
	      ./setup.sh [OPTIONS] |& tee \~/tmp/setup.log

	  Alternatively, if you wish to see only stderr, redirecting stdout to a
	  file for inspection at a later time...
	      ./setup.sh [OPTIONS] >\~/tmp/setup.log

	Output:
	  Upon successful termination of this script, you should have a CAC-aware Git
	  in your path (/usr/local/bin), and a startup script in /etc/profile.d, which
	  automatically makes the environment changes needed to use the CAC-aware Git
	  each time you start a Cygwin shell.

	  Note: If you wish to inhibit loading the PKCS11 engine temporarily, you have
	  several options:
	    1. Set environment variable INHIBIT_CAC_ENABLED_GIT=1 to prevent the env
	       vars from being defined each time you start a Cygwin shell.
	    2. Run disable_cac_aware_git from within your current Cygwin bash shell.
	       Note: There's a matching enable_cac_aware_git should you wish to
	       re-enable.

	  Note: This script installs the default (non-CAC-aware) Cygwin Git in
	  /usr/bin; thus, a more definitive way to disable the CAC customizations is
	  simply to use the default git in /usr/bin instead of the customized git in
	  /usr/local/bin. To facilitate this, the startup script also creates...
	    ncgit
	  ...as an alias to the default Git.

	eof
}
error() {
	local usage=no
	if [[ $1 == --usage ]]; then
		usage=yes
		shift
	fi
	echo >&2 "$@"
	if [[ $usage == yes ]]; then
		# Pass error along to usage for display.
		usage "$@"
	fi
	# TODO: Consider adding an error code option.
	exit 1
}
list_steps() {
	cat <<-eof
	install_cyg_pkg
	    Install Cygwin packages for NSS and OpenSSL, as well as some packages that
	    will be required by the build process.
	download_source
	    Download source code for several OpenSC libraries and tools, as well as
	    the source for cURL and Git (both of which we'll be patching and
	    building).
	build_opensc
	    Build the OpenSC libraries/tools.
	create_certs
	    Download 3 separate DOD root CA cert bundles, convert to .pem format, and
	    combine with the default CA bundles provided with openssl to create a
	    single cert bundle that can be used with Git's sslCAInfo config option.
	patch_curl
	    Modify the cURL source code to support dynamic loading of the PKCS11
	    engine built in an earlier step.
	build_curl
	    Build the modified cURL (both standalone and dynamic library)
	configure_openssl_conf
	    Create an OpenSSL configuration file that will enable the PKCS11 engine to
	    be loaded dynamically by the cURL library.
	patch_git
	    Modify the Git source to do the following:
	    -Add support for several SSL-related options that are needed to configure
	     the cURL lib to use PKCS11.
	    -Add support for an environment variable (GIT_INHIBIT_ASKPASS), which can
	     be set to prevent Git from trying to use the default Tk GUI prompt (which
	     can fail on non-X11 systems) for collecting passwords.
	build_git
	    Build the modified Git
	install_env_script
	    Install startup script /etc/profile.d/cac-enabled-git.sh, whose purpose is
	    to ensure that the environment variables required for proper operation are
	    set automatically each time a Cygwin shell is started.
	    Note: To disable this mechanism at a later date, you can either...
	      -Set env var INHIBIT_CAC_ENABLED_GIT=1 (persistent change)
	      -Run disable_cac_aware_git from a running Cygwin shell (disables in
	       current shell only, and can be re-enabled with enable_cac_aware_git).
	eof
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
set_start_step() {
	if [[ $Step_mode == only ]]; then
		error --usage "Illegal attempt to use --start-step: mutually-exclusive options specified"
	fi
	Start_step=$1
	Step_mode=range
}
set_end_step() {
	if [[ $Step_mode == only ]]; then
		error --usage "Illegal attempt to use --end-step: mutually-exclusive options specified"
	fi
	End_step=$1
	Step_mode=range
}
add_skip_steps() {
	if [[ $Step_mode == only ]]; then
		error --usage "Illegal attempt to use --skip-steps: mutually-exclusive options specified"
	fi
	# Update hash of steps to skip.
	for s in ${1//,/ }; do
		Skip_steps[$s]=yes
	done
}
add_only_steps() {
	if [[ $Step_mode == range ]]; then
		error --usage "Illegal attempt to use --only-steps: mutually-exclusive options specified"
	fi
	# Update hash of steps to run
	for s in ${1//,/ }; do
		Only_steps[$s]=yes
	done
	Step_mode=only
}
set_card_id() {
	if [[ $1 != [0-9][0-9] ]]; then
		error --usage "Invalid id format for card-id: $1"
	fi
	Card_id=$1
}
confirm_cygwin64() {
	echo >&2 "Warning! This script has not been tested on 64-bit versions of Cygwin."
	echo >&2 "Do you wish to proceed? (y/[n])"
	read ans
	if [[ $ans != [yY] ]]; then
		return 1
	fi
}
# Assumption: errexit option has not yet been enabled.
process_opt() {
	# TODO: Consider a different way, which would handle defaults.
	# TODO: Perhaps put these in array, at least...
	local -a longs=(
		"help" version list-steps
		start-step: end-step: skip-steps: only-steps:
		card-id: ca-bundle-dir: ca-bundle-name: openssl-conf:
		skip-cygwin-install use-cygwin64 no-install no-execute)
	# getopt idiosyncrasy: 1st arg specified to a long opt intended to be used to build an array can lose the 1st arg if
	# there no short opts are specified (e.g., with -o).
	# Getopt workaround: To facilitate proper error reporting, I'm calling getopt up to twice: once to validate, and
	# then, only if valid, to get the actual parsed options. Note that if validation fails, the stderr redirection
	# ensures that I have the error text for reporting via error(); in the second call, the -q option ensures there can
	# be no error text, so the redirection is harmless.
	cmd='getopt 2>&1 $quiet -os: -l$(IFS=, ; echo "${longs[*]}") -- "$@"'
	for mode in check real; do
		if [[ $mode == check ]]; then
			quiet=-Q
			# Caveat: Doing this way because the local assignment discards any error; eval doesn't.
			eval $cmd
		else
			quiet=-q
			local opts=$(eval $cmd)
		fi
		if (( $? )); then
			error --usage "$opts"
		fi
	done
	eval set -- "$opts"
	while (($#)); do
		local v=$1
		shift
		case $v in
			--help)
				show_help
				exit 0;;
			--version)
				echo "$(basename $0): A script to automate creation of a CAC-aware Git: Version $VERSION"
				exit 0;;
			--list-steps)
				list_steps
				exit 0;;
			-s | --start-step)
				set_start_step $1
				shift;;
			--end-step)
				set_end_step $1
				shift;;
			--skip-steps)
				add_skip_steps $1
				shift;;
			--only-steps)
				add_only_steps $1
				shift;;
			--card-id)
				set_card_id $1
				shift;;
			--ca-bundle-dir) Opts[ca-bundle-dir]=$1; shift;;
			--ca-bundle-name) Opts[ca-bundle-name]=$1; shift;;
			--openssl-conf) Opts[openssl-conf]=$1; shift;;
			# TODO: Perhaps just use the --skip-step mechanism internally.
			--skip-cygwin-install)
				Opts[skip-cygwin-install]=yes
				# This option is really just syntactic sugar.
				Skip_steps[install_cyg_pkg]=yes;;
			--use-cygwin64)
				if ! confirm_cygwin64; then
					exit 0
				fi
				Opts[use-cygwin64]=yes;;
			--no-install)
				Opts[no-install]=yes
				Make_install="echo Skipping install...";;
			--no-execute)
				Opts[no-execute]=yes;;
		esac
	done
}

detect_cac_card() {
	if [[ -n $Card_id ]]; then
		# No need for detection: user specified with option.
		return 0
	fi
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
# Caveat: Running cygwin setup program standalone fails if the install-info
# utility is not in the path. Appears to be a cygwin bug/oversight.
# Note: Using setup -P for an already-installed package appears to re-install harmlessly.
# TODO: Provide special arg for skipping cygwin install (so user needn't know which step follows).
# Important Note: If unattended setup causes problems on user's machine, he can install the packages himself through the
# setup gui and re-run with --skip-cygwin-install or --skip-step install_cyg_pkg.
install_cyg_pkg() {
	# TODO: Document purpose of all these...
	# Caveat: Make sure info pkg is installed first.
	# Rationale: I've run into issues attempting to install packages when install-info (in info package) didn't exist.
	# Note: libexpat-devel and gettext-devel appear to be hidden dependencies of various configure/make scripts.
	local -a pkgs=(
		info make binutils gcc-g++ libiconv-devel
		git dos2unix patch
		libnss3 openssl openssl-devel libopenssl100
		chkconfig pkg-config automake autoconf libtool cygwin-devel
		libexpat-devel gettext-devel
	)
	# Obtain latest copy of appropriate setup program and make executable.
	local url=https://cygwin.com/setup-x86${Opts[use-cygwin64]:+_64}.exe
	local opt="-q -N -d -W -B"
	local setup=./${url##*/}
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
	local repos=(
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
	local libs=(libp11 engine_pkcs11 OpenSC)
	for d in "${libs[@]}"; do
		pushd $d
		# TODO: Make sure error handled as desired (with effective popd).
		# simulate error somehow to test...
		# TEMP DEBUG - Don't really install...
		./bootstrap && ./configure && make && $Make_install && popd
	done
}
create_certs() {
	# Make sure the directory exists.
	local dir="${Opts[ca-bundle-dir]}"
	if [[ ! -d $dir ]]; then
	   mkdir -p "$dir"
	fi
	local cert_path="$dir/${Opts[ca-bundle-name]}.pem"
	# Seed the file with the CA bundles that ship with openssl
	cat /usr/ssl/certs/ca-bundle{,.trust}.crt >"$cert_path"

	# Append the DOD root certs (after converting from .p7b to .pem format)
	local certs=(rel3_dodroot_2048 dodeca dodeca2)
	local url=http://dodpki.c3pki.chamb.disa.mil
	for cert in "${certs[@]}"; do
		wget -O- $url/$cert.p7b | openssl pkcs7 -inform DER -outform PEM -print_certs
	done >>"$cert_path"
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
	+#ifdef HAVE_OPENSSL_ENGINE_H
	+  if (data->state.engine) {
	+    /* state.engine existing means curl_ossl_set_engine was
	+    * previously successful. Because curl_ossl_set_engine worked,
	+    * we can query the already-set engine for that handle and use
	+    * that to increment a reference:
	+    */
	+    Curl_ssl_set_engine(outcurl, ENGINE_get_id(data->state.engine));
	+  }
	+#endif /* HAVE_OPENSSL_ENGINE_H */
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
enable_cac_aware_git() {
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
}
disable_cac_aware_git() {
	for v in \$(env|grep GIT_SSL_); do
		unset \${v%%=*};
	done
	unset OPENSSL_CONF
	unset GIT_INHIBIT_ASKPASS
}
# Note: User can disable automatic CAC setup at shell startup simply by defining a non-empty INHIBIT_CAC_ENABLED_GIT env
# var. To disable/re-enable in a running shell, he can use the following functions:
#     enable_cac_aware_git
#     disable_cac_aware_git
if [[ \$(uname -o) == Cygwin && -z \$INHIBIT_CAC_ENABLED_GIT ]]; then
	enable_cac_aware_git
fi
# As a convenience, provide an alias to "non-CAC-aware" git.
alias ncgit=/usr/bin/git
eof
}

process_opt "$@"
clean_env
# Always detect CAC card, since the results of id detection may be needed in other steps.
detect_cac_card
check_prerequisites

# Default mode from here on is to fail on error with indication of last step completed.
# Note: Step functions with a need (e.g., install_cyg_pkg) may *temporarily* unset.
# Caveat: Take care not to generate spurious errors: e.g., do ((++var)) instead of ((var++) when var could be 0.
set -e
trap on_exit EXIT
run

# Short-term TODO
# 1. Add cygwin 64 option

# vim:ts=4:sw=4:tw=120
