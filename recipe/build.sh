#!/bin/bash

set -xeuo pipefail

# Activation scripts

mkdir -p ${PREFIX}/etc/conda/activate.d
mkdir -p ${PREFIX}/etc/conda/deactivate.d

get_cpu_arch() {
  local CPU_ARCH
  if [[ "$1" == *"-64" ]]; then
    CPU_ARCH="x86_64"
  elif [[ "$1" == *"-ppc64le" ]]; then
    CPU_ARCH="powerpc64le"
  elif [[ "$1" == *"-aarch64" ]]; then
    CPU_ARCH="aarch64"
  elif [[ "$1" == *"-s390x" ]]; then
    CPU_ARCH="s390x"
  else
    echo "Unknown architecture"
    exit 1
  fi
  echo $CPU_ARCH
}

get_triplet() {
  if [[ "$1" == linux-* ]]; then
    echo "$(get_cpu_arch $1)-conda-linux-gnu"
  elif [[ "$1" == osx-64 ]]; then
    echo "x86_64-apple-darwin13.4.0"
  elif [[ "$1" == osx-arm64 ]]; then
    echo "arm64-apple-darwin20.0.0"
  elif [[ "$1" == win-64 ]]; then
    echo "x86_64-w64-mingw32"
  else
    echo "unknown platform"
  fi
}

# These sysconfigdata do not have -B $PREFIX/share/compiler_compat
# which is bad for cross compilation
case ${cross_target_platform} in
  linux-*)
    _CONDA_PYTHON_SYSCONFIGDATA_NAME=_sysconfigdata_$(get_cpu_arch ${cross_target_platform})_conda_linux_gnu
    ;;
  osx-64)
    _CONDA_PYTHON_SYSCONFIGDATA_NAME=_sysconfigdata_x86_64_apple_darwin13_4_0
    ;;
  osx-arm64)
    _CONDA_PYTHON_SYSCONFIGDATA_NAME=_sysconfigdata_arm64_apple_darwin20_0_0
    ;;
  win-64)
    _CONDA_PYTHON_SYSCONFIGDATA_NAME=_sysconfigdata_win_64
    ;;
  *)
    exit 1
    ;;
esac

TARGET="$(get_triplet $cross_target_platform)"
if [[ "$cross_target_platform" == osx-* ]]; then
  CC_FOR_TARGET="${TARGET}-clang"
  CXX_FOR_TARGET="${TARGET}-clang++"
else
  CC_FOR_TARGET="${TARGET}-gcc"
  CXX_FOR_TARGET="${TARGET}-g++"
fi

if [[ "$freethreading" == "yes" ]]; then
  PY_THREAD="t"
else
  PY_THREAD=""
fi

mkdir scripts

cp "${RECIPE_DIR}"/activate*.* scripts/
cp "${RECIPE_DIR}"/deactivate*.* scripts/

find scripts -name "activate*.*" -not -name "*.bak" -exec sed -i.bak "s|@CC@|${CC_FOR_TARGET}|g"  "{}" \;
find scripts -name "activate*.*" -not -name "*.bak" -exec sed -i.bak "s|@CXX@|${CXX_FOR_TARGET}|g"  "{}" \;
find scripts -name "activate*.*" -not -name "*.bak" -exec sed -i.bak "s|@PY_THREAD@|${PY_THREAD}|g"  "{}" \;
find scripts -name "activate*.*" -not -name "*.bak" -exec sed -i.bak "s|@PY_VER@|${version}|g"  "{}" \;
find scripts -name "activate*.*" -not -name "*.bak" -exec sed -i.bak "s|@_CONDA_PYTHON_SYSCONFIGDATA_NAME@|${_CONDA_PYTHON_SYSCONFIGDATA_NAME}|g"  "{}" \;

rm scripts/*.bak

cat scripts/activate-cross-python.sh

cp scripts/activate-cross-python.sh ${PREFIX}/etc/conda/activate.d/activate_z-${PKG_NAME}.sh
cp scripts/deactivate-cross-python.sh ${PREFIX}/etc/conda/deactivate.d/deactivate_z-${PKG_NAME}.sh

# Python launcher shim program (see shim/shim.c for details)

cp -r "${RECIPE_DIR}/shim" .
pushd shim
mkdir -p ${PREFIX}/bin
sed -i.bak "s#@PREFIX@#$PREFIX#g" shim.c
${CC} ${CFLAGS} ${LDFLAGS} shim.c -o ${PREFIX}/bin/cross_python_shim
popd
