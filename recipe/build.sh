#! /bin/bash

set -xeuo pipefail

# Activation scripts

mkdir -p ${PREFIX}/etc/conda/activate.d
mkdir -p ${PREFIX}/etc/conda/deactivate.d
cp "${RECIPE_DIR}"/activate-cross-python.sh ${PREFIX}/etc/conda/activate.d/activate_z-${PKG_NAME}.sh
cp "${RECIPE_DIR}"/deactivate-cross-python.sh ${PREFIX}/etc/conda/deactivate.d/deactivate_z-${PKG_NAME}.sh

# Python launcher shim program (see its README)

cp -r "${RECIPE_DIR}/shim" .
pushd shim
printf "%s\\0" "${PREFIX}" >src/prefix.bin  # quasi-hack needed to get prefix rewriting to work
cargo install --path . --root "${PREFIX}"
rm -f "${PREFIX}/.crates.toml" "${PREFIX}/.crates2.json"
popd
