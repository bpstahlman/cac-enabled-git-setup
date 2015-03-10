# cac-enabled-git-setup
Bash script that builds (on Linux or Cygwin) a version of Git capable of using a CAC card for authentication.

# Before you start...
- Obviously, you'll need a government-issued CAC card.
- If you're running under...
  - ...Linux or OS X, you'll need to install the packages listed under the section entitled *Package Prerequisites*.
  - ...Windows, you'll need a basic Cygwin installation, augmented with wget (which is not part of the Cygwin default install, but may be obtained from the *Web* package).
**Note**: Cygwin users will also need the packages listed under *Package Prerequisites*, but unless you explicitly disable it (with the --skip-cygwin-install option), the installer will attempt to install the requisite packages for you.


# Package Prerequisites
> **Note:** Package names may vary from one package manager to the next. Thus, I will not attempt to make an exhaustive list here. If the script should fail because of a missing dependency, it's easy to resume at the failed step after you've installed the missing dependency.

 - wget
 **Note:** If you're using Cygwin, wget is the only package you need - the rest will be installed automatically.
 _**Build Tools**_
 - patch
 - make, binutils, gcc-g++, automake, autoconf, libtool, etc...
 _**Libraries**_
 - libnss (Network Security Services)
 - libopenssl



# Instructions for Use
#### 1. Install the prerequisites
+ _**Windows (if you don't already have Cygwin)**_
    Go to [Cygwin Install Page](https://cygwin.com/install.html) and run the setup program, choosing all defaults until you get to the _Select Packages_ screen. Keep the defaults for everything except the *Web* section: expand it and select the *wget* package for installation.   
    **Note:** Unless you already have 64-bit Cygwin installed, I would recommend using the 32-bit version, as this script has been tested only on 32-bit.
+ _**Windows (if you already have Cygwin)**_
	Make sure you have a working *wget* program in your PATH. If not, you can get it from the Cygwin *Web* package.
+ _**Linux / OS X**_
    Use your package manager to install the libraries listed under _**Package Prerequisites**_. Don't worry too much about missing dependencies. If there are any, the setup will fail, but you can easily restart with the *`--start-step`* option (after installing the missing dependencies).
    
#### 2.	Open a terminal running Bash.
> Cygwin users should have a link to *Cygwin Terminal* on their desktops and in the Windows *Start Menu*.
#### 3.	Create an empty directory and add the latest version of this script to it.
**Note:** If you already have Git, the following command will create the directory and add the script automatically...

        git clone --config core.autocrlf=input https://github.com/bpstahlman/cac-enabled-git-setup.git

    ...otherwise, you can use the "Download ZIP" option in Github, and manually extract the script file to the directory you've created. 
> **Caveat to Windows Users:** The script will not run if its line endings are converted from "UNIX" to "DOS". Neither of the methods mentioned above should perform such a conversion, but it's something to be aware of if you obtain the script some other way...

#### 4.	Make sure the script is "executable".
`chmod u+x build-cac-enabled-git`
#### 5.	Make sure your *CAC* card is inserted in its slot.
#### 6.	From the directory containing the script, run the script with the default options, piping the output to a logfile to facilitate any post-mortem analysis: e.g.,
`./build-cac-enabled-git |& tee setup.log`
> **Note:** Before running the script, you may wish to use its `--help` option to get a better feel for what options are available (especially useful if you need to restart after error). Additionally, the help output provides an overview of what's being done, and also gives some post-installation usage tips.
#### 7.	Open a _**new**_ terminal and test your new CAC-ified Git by attempting to connect to a repo requiring CAC authentication.
**Explanation:** The environment variables that tell Git to load the PKCS11 engine are set within a shell startup script, which won't be run until you open a new shell.

# Post-Installation Tips

