# cac-enabled-git-setup
Bash script that builds (on Linux or Cygwin) a version of Git capable of using a CAC card for authentication.

#Before you start...
- Obviously, you'll need a government-issued CAC card.
- If you're running under Windows...
  - You'll need a basic Cygwin installation, augmented with wget (which is not part of the Cygwin default install, but may be obtained from the *Web* package).

> *Note:* 32-bit Cygwin is preferred, though there's an (untested) option to force use of 64-bit Cygwin. (Actually, the setup program doesn't really care which version you're using unless you're letting it install the package prerequisites - i.e., you haven't specified the --skip-cygwin-install option).

  - If you're running Linux or OS X, you'll need to install the packages listed under the section entitled *Package Prerequisites*.

#Instructions for Use

