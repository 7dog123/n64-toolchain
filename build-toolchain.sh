#! /bin/bash
# N64 MIPS GCC toolchain build/install script (runs under UNIX systems).
# (c) 2012-2021 Shaun Taylor and libDragon Contributors.
# See the root folder for license information.


# Before calling this script, make sure you have all required
# dependency packages installed in your system.  On a Debian-based systems
# this is achieved by typing the following commands:
#
# sudo apt-get update && sudo apt-get upgrade
# sudo apt-get install -yq wget bzip2 gcc g++ make file libmpfr-dev libmpc-dev zlib1g-dev texinfo git gcc-multilib

# Exit script on error
set -e

TARGET=mips64-elf
OSVER=${uname}

if [ "${OSVER:0:10}" == MINGW64_NT ]; then
	export CC=x86_64-w64-mingw32-gcc
	TARG_XTRA_OPTS="--host=x86_64-w64-mingw32"
elif [ "${OSVER:0:10}" == MINGW32_NT ]; then
	export CC=i386-w64-mingw32-gcc
        TARG_XTRA_OPTS="--host=i386-w64-mingw32"
else
	TARG_XTRA_OPTS=""
fi

INSTALL_PATH="${N64_INST:-/usr/local/n64_toolchain}"
# rm -rf "$INSTALL_PATH" # We should probably do a clean install?!

if [ "${OSVER:0:10}" == MINGW64_NT ] && [ "${OSVER:0:10}" == MINGW32_NT ]; then
       mkdir -p "$INSTALL_PATH" # But make sure the install path exists!
else 
       sudo mkdir -p "$INSTALL_PATH" # But make sure the install path exists!
fi

BINUTILS_V=2.36.1
GCC_V=11.2.0
NEWLIB_V=4.1.0


# Determine how many parallel Make jobs to run based on CPU count
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN)}"
JOBS="${JOBS:-1}" # If getconf returned nothing, default to 1


# Check if a command-line tool is available: status 0 means "yes"; status 1 means "no"
command_exists () {
  (command -v "$1" >/dev/null 2>&1)
  return $?
}

# Download the file URL using wget or curl (depending on which is installed)
download () {
  if   command_exists wget ; then wget --no-check-certificate -c  "$1" # checking the certificate chain is not done by curl and requires extra dependencies.
  elif command_exists curl ; then curl -LO "$1"
  else
    echo "Install 'wget' or 'curl' to download toolchain sources" 1>&2
    return 1
  fi
}

echo "Stage: Download and extract dependencies"
test -f "binutils-$BINUTILS_V.tar.gz" || download "https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_V.tar.gz"
test -d "binutils-$BINUTILS_V"        || tar -xzf "binutils-$BINUTILS_V.tar.gz"

test -f "gcc-$GCC_V.tar.gz"           || download "https://ftp.gnu.org/gnu/gcc/gcc-$GCC_V/gcc-$GCC_V.tar.gz"
test -d "gcc-$GCC_V"                  || tar -xzf "gcc-$GCC_V.tar.gz" --checkpoint=.100 # TODO: there must be a better way of showing progress (given such a large file)!

test -f "newlib-$NEWLIB_V.tar.gz"     || download "https://sourceware.org/pub/newlib/newlib-$NEWLIB_V.tar.gz"
test -d "newlib-$NEWLIB_V"            || tar -xzf "newlib-$NEWLIB_V.tar.gz"

if [ "${OSVER:0:10}" == MINGW64_NT ] && [ "${OSVER:0:10}" == MINGW32_NT ]; then
GMP_V=6.2.0
MPC_V=1.2.1
MPFR_V=4.1.0
MAKE_V=4.2.1
# Optional dependency handling
# Copies the FP libs into GCC sources so they are compiled as part of it
  test -f "gmp-$GMP_V.tar.xz"         || download "https://ftp.gnu.org/gnu/gmp/gmp-$GMP_V.tar.xz"
  test -d "gmp-$GMP_V"                || tar -xf "gmp-$GMP_V.tar.xz" -c gcc-$GCC_V/gmp# note no .gz download file currently available

  test -f "mpc-$MPC_V.tar.gz"         || download "https://ftp.gnu.org/gnu/mpc/mpc-$MPC_V.tar.gz"
  test -d "mpc-$MPC_V"                || tar -xzf "mpc-$MPC_V.tar.gz" -C gcc-$GCC_V/mpc

  test -f "mpfr-$MPFR_V.tar.gz"       || download "https://ftp.gnu.org/gnu/mpfr/mpfr-$MPFR_V.tar.gz"
  test -d "mpfr-$MPFR_V"              || tar -xzf "mpfr-$MPFR_V.tar.gz" -C gcc-$GCC_V/mpfr
# Certain platforms might require Makefile cross compiling

  test -f "make-$MAKE_V.tar.gz"       || download "https://ftp.gnu.org/gnu/make/make-$MAKE_V.tar.gz"
  test -d "make-$MAKE_V"              || tar -xzf "make-$MAKE_V.tar.gz"
fi

echo "Stage: Compile toolchain"

echo "Compiling binutils-$BINUTILS_V"

cd "binutils-$BINUTILS_V"
./configure \
  --prefix="$INSTALL_PATH" \
  --target="$TARGET" \
  --with-cpu=mips64vr4300 \
  --disable-werror \
  $TARG_XTRA_OPTS
make -j "$JOBS"

if [ "${OSVER:0:10}" == MINGW64_NT ] && [ "${OSVER:0:10}" == MINGW32_NT ]; then
	make install-strip
else
	sudo make install-strip || su -c "make install-strip"
fi

make distclean # Cleanup to ensure we can build it again
echo "Finished Compiling binutils-$BINUTILS_V"

echo "Compiling native build of GCC-$GCC_V for MIPS N64 - (pass 1) outside of the source tree"
# TODO why do we bother if we already have a good (compatible) compiler installed?! 
# e.g. we could use ` whereis` ?! it does not need to be up-to-date as we have a second pass?!
# This would seriously decrease build time.
cd ..
rm -rf gcc_compile
mkdir gcc_compile
cd gcc_compile
../"gcc-$GCC_V"/configure \
  --prefix="$INSTALL_PATH" \
  --target="$TARGET" \
  --with-arch=vr4300 \
  --with-tune=vr4300 \
  --enable-languages=c,c++ \
  --without-headers \
  --with-newlib \
  --disable-libssp \
  --enable-multilib \
  --disable-shared \
  --with-gcc \
  --disable-threads \
  --disable-win32-registry \
  --disable-nls \
  --disable-werror \
  --with-system-zlib \
  $TARG_XTRA_OPTS
make all-gcc -j "$JOBS"
make all-target-libgcc -j "$JOBS"
if [ "${OSVER:0:10}" == MINGW64_NT ] && [ "${OSVER:0:10}" == MINGW32_NT ]; then
	make install-strip-gcc
	make install-target-libgcc
else
	sudo make install-strip-gcc || su -c "make install-strip-gcc"
	sudo make install-target-libgcc || su -c "make install-target-libgcc"
fi

echo "Finished Compiling GCC-$GCC_V for MIPS N64 - (pass 1) outside of the source tree"

echo "Compiling newlib-$NEWLIB_V"
cd ../"newlib-$NEWLIB_V"

# Set PATH for newlib to compile using GCC for MIPS N64 (pass 1)
export PATH="$PATH:$INSTALL_PATH/bin" #TODO: why is this export?!
CFLAGS_FOR_TARGET="-DHAVE_ASSERT_FUNC -O2" ./configure \
  --target="$TARGET" \
  --prefix="$INSTALL_PATH" \
  --with-cpu=mips64vr4300 \
  --disable-threads \
  --disable-libssp \
  --disable-werror \
  $TARG_XTRA_OPTS
make -j "$JOBS"

if [ "${OSVER:0:10}" == MINGW64_NT ] && [ "${OSVER:0:10}" == MINGW32_NT ]; then
	make install
else
	sudo env PATH="$PATH" make install || su -c "env PATH=\"$PATH\" make install"
fi
echo "Finished Compiling newlib-$NEWLIB_V"

if [ "${OSVER:0:10}" == MINGW64_NT ] && [ "${OSVER:0:10}" == MINGW32_NT ]; then
echo "Compiling make-$MAKE_V" # As make is otherwise not available on Windows
cd ../"make-$MAKE_V"
  ./configure \
    --prefix="$INSTALL_PATH" \
    --disable-largefile \
    --disable-nls \
    --disable-rpath \
    $TARG_XTRA_OPTS
make -j "$JOBS"
make install-strip
make clean

echo "Finished Compiling make-$MAKE_V"
fi
