# cac-enabled-git-setup
Bash script that builds a version of Git capable of using a CAC card for authentication.
### **Caveat!** So far tested on the following platforms:
- Windows (Cygwin)
- Ubuntu Linux

# Before you start...
- A government-issued _Common Access Card_ (CAC) with drivers installed.
- If you're running under...
  - ...Windows, you'll need a basic Cygwin installation, augmented with wget (which is not part of the Cygwin default install, but may be obtained from the *Web* package).
**Note**: Cygwin users will also need the packages listed under *Package Prerequisites*, but this script will install them automatically.
  - ...Ubuntu Linux, you shouldn't need to install any prerequisites, as this script will handle it.
  - ...Non-Ubuntu Linux, you'll need to install the packages listed under the section entitled *Package Prerequisites*.


# Package Prerequisites
> **Note:** Package names may vary from one package manager to the next. Thus, I will not attempt to make an exhaustive list here. If the script should fail because of a missing dependency, it's easy to resume at the failed step after you've installed the missing dependency.

 - wget
 **Note:** If you're using Cygwin, wget is the only package you need: the rest will be installed automatically.
 
- _**Build Tools**_
     - git
     - patch
     - make, gcc, automake, autoconf, m4, libtool
- _**Libraries**_
     - libnss (Network Security Services)
     - libopenssl, libssl-dev
- _**Misc**_
     - gettext
     - libexpat1-dev
     - libpcsclite-dev



# Instructions for Use
#### 1. Install the prerequisites
+ _**Windows (if you don't already have Cygwin)**_
    Go to [Cygwin Install Page](https://cygwin.com/install.html) and run the setup program, choosing all defaults until you get to the _Select Packages_ screen. Keep the defaults for everything except the *Web* section: expand it and select the *wget* package for installation.   
    **Note:** Unless you already have 64-bit Cygwin installed, I would recommend using the 32-bit version, as this script has been tested only on 32-bit.
+ _**Windows (if you already have Cygwin)**_
	Make sure you have a working *wget* program in your PATH. If not, you can get it from the Cygwin *Web* package.
+ _**Ubuntu Linux**_
    This script can install the prerequisite packages automatically.
+ _**Linux (Other)**_
    Use your package manager to install the libraries listed under _**Package Prerequisites**_ (or functional equivalents). Don't worry too much about missing dependencies. If there are any, the setup will fail, but you can easily restart with the *`--start-step`* option (after installing the missing dependencies).
    
#### 2.	Open a terminal.
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
`sudo ./build-cac-enabled-git |& tee setup.log`
    > **Cygwin Note:** `sudo` is for Linux users only.
    > **Note:** Before running the script, you may wish to use its `--help` option to get a better feel for what options are available (especially useful if you need to restart after error). Additionally, the help output provides an overview of what's being done, and also gives some post-installation usage tips.
#### 7.	Upon successful script termination, open a _**new**_ terminal and test your new CAC-ified Git by attempting to connect to a repo requiring CAC authentication.
**Explanation:** The environment variables that tell Git to load the _PKCS#11_ engine are loaded by a shell startup script, which won't be run until you open a new shell.

# Post-Installation Tips
### Username/Password/Pin prompting
Unless you unset environment variable `GIT_INHIBIT_ASKPASS` (set in the startup script installed to `/etc/profile.d/cac-enabled-git.sh`), the custom Git built by this script will perform all password prompting in the console.
> **Explanation:** By default, Git will attempt to bring up a _Tk_ dialog for such prompts, but if you don't have an X server on your system, the attempt will fail with error. A patch applied to the Git source changes the default behavior to use a console prompt, but only if `GIT_INHIBIT_ASKPASS` is set.
> **Note:** You could alternatively null the `GIT_ASKPASS` environment variable to accomplish the same thing. In fact, `GIT_INHIBIT_ASKPASS` may be removed in a future version of this script.

If you have a working X server and wish to use GUI password prompts, simply set `GIT_INHIBIT_ASKPASS=no` (or unset altogether), and ensure `GIT_ASKPASS` is not set to an empty string.

> **Caveat:** Currently, the _openssl_ library does not (by default) support anything but console prompts: thus, _**even if Git is able to use Tk dialogs for username/password prompts, you'll still be forced to enter you PKCS#11 pin at the console**_. Thus, for the sake of consistency, even those with an X server may wish to stick with console prompts...

### Running a GUI version of Git

* X server required
> _**Cygwin Users:**_ You can start an X server like so (assuming you didn't inhibit X installation with script options)...

        startxwin&

* For reasons described in an earlier caveat, you will need to enter your PKCS#11 pin in a console prompt, which means _**you'll need to run `gitk` in the foreground**_ and leave the invoking terminal open. E.g., to start graphical Git:
            
        gitk
        
> **Note:** Entering passwords this way may seem a bit awkward at first, but keep in mind that you won't need to enter a pin until you do something that hits the server, and a typical Git workflow involves predominantly local manipulations/visualizations.
> **Also Note:** A future version of this script may use the _OpenSSL_ UI customization API to build a custom openssl library, which supports GUI prompts.

# Attributions
Much of the background material used to develop this script came from an article by Jerry Quassar, entitled [Using git with CAC](https://rite.sd.spawar.navy.mil/confluence/display/RITE/Using+git+with+CAC).
