#! /bin/bash

set -xeuo pipefail

# Activation scripts

mkdir -p ${PREFIX}/etc/conda/activate.d
mkdir -p ${PREFIX}/etc/conda/deactivate.d

CC=$(basename ${CC})
CXX=$(basename ${CXX})

find "${RECIPE_DIR}" -name "activate*.*" -exec sed -i.bak "s|@CC@|${CC}|g"  "{}" \;
find "${RECIPE_DIR}" -name "activate*.*" -exec sed -i.bak "s|@CXX@|${CXX}|g"  "{}" \;

cat "${RECIPE_DIR}"/activate-cross-python.sh

cp "${RECIPE_DIR}"/activate-cross-python.sh ${PREFIX}/etc/conda/activate.d/activate_z-${PKG_NAME}.sh
cp "${RECIPE_DIR}"/deactivate-cross-python.sh ${PREFIX}/etc/conda/deactivate.d/deactivate_z-${PKG_NAME}.sh

# Python launcher shim program (see shim/shim.c for details)

cp -r "${RECIPE_DIR}/shim" .
pushd shim
mkdir -p ${PREFIX}/bin
sed -i.bak "s#@PREFIX@#$PREFIX#g" shim.c
${CC} ${CFLAGS} ${LDFLAGS} shim.c -o ${PREFIX}/bin/cross_python_shim
popd
