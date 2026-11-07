#!/bin/bash
# cross-python for @CROSS_TARGET_PLATFORM@ on a unix build machine: build
# extensions for the target python in $PREFIX with the build python in
# $BUILD_PREFIX and the clang_win-64 toolchain (MSVC ABI).
# Windows has no _sysconfigdata and crossenv does not support Windows targets,
# so the build python is pointed at the target through environment variables
# and the sitecustomize.py installed in etc/conda/cross-python.

# TEMPORARY workaround for conda-forge/clang-win-activation-feedstock#75
# (fixed by #76): winsdk 10.0.26100.0 build 28 does not extract
# "Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi", so
# include/shared/basetsd.h is missing. Extract that MSI from the SDK ISO,
# merge its headers into the SDK and regenerate the VFS overlay. Drop this
# function once winsdk build >= 29 is published.
_cross_python_fix_winsdk() {
  local act winsdk_version winsdk_url winsdk_dir
  act="${BUILD_PREFIX}/etc/conda/activate.d/activate-winsdk.sh"
  [[ -f "${act}" && -n "${CONDA_BUILD_WINSDK:-}" ]] || return 0
  winsdk_version="$(sed -n 's/^WINSDK_VERSION=//p' "${act}")"
  winsdk_url="$(sed -n 's/^WINSDK_URL=//p' "${act}")"
  winsdk_dir="${CONDA_BUILD_WINSDK}/winsdk-${winsdk_version}"
  [[ -d "${winsdk_dir}/include" && ! -f "${winsdk_dir}/include/shared/basetsd.h" ]] || return 0

  echo "cross-python: winsdk ${winsdk_version} lacks shared/basetsd.h, extracting the OnecoreUap headers"
  # same steps as activate-winsdk.sh; msiextract needs the cabs next to the msi
  (
    set -e
    unset SSL_CERT_DIR
    unset SSL_CERT_FILE
    cd "${winsdk_dir}"
    rm -rf onecoreuap
    mkdir onecoreuap
    cd onecoreuap
    curl -L "${winsdk_url}" -o win10sdk.iso
    7z x win10sdk.iso -aoa > /dev/null
    mkdir tmp
    msiextract -C tmp Installers/"Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi" > /dev/null
    cp -rn "tmp/Program Files/Windows Kits/10/Include/${winsdk_version}"/* "${winsdk_dir}/include/"
    cd "${winsdk_dir}"
    rm -rf onecoreuap

    # activate-winsdk.sh writes the overlay only on case-sensitive filesystems;
    # regenerate it with the same loop so it covers the new headers
    if [[ -f winsdk_vfs_overlay.yaml ]]; then
      echo "version: 0" > winsdk_vfs_overlay.yaml
      echo "case-sensitive: false" >> winsdk_vfs_overlay.yaml
      echo "roots:" >> winsdk_vfs_overlay.yaml
      for dir in $(find "${winsdk_dir}/include" -type d); do
        files=$(find "$dir" -maxdepth 1 -name "*.h")
        if [[ "$files" != "" ]]; then
          echo "  - name: \"$dir\"" >> winsdk_vfs_overlay.yaml
          echo "    type: directory" >> winsdk_vfs_overlay.yaml
          echo "    contents:" >> winsdk_vfs_overlay.yaml
          for f in $files; do
            echo "      - name: \"$(basename "$f")\"" >> winsdk_vfs_overlay.yaml
            echo "        type: file" >> winsdk_vfs_overlay.yaml
            echo "        external-contents: \"$f\"" >> winsdk_vfs_overlay.yaml
          done
        fi
      done
    fi
  ) || echo "cross-python: could not add the OnecoreUap headers to the winsdk" >&2
}

if [[ "${CONDA_BUILD:-0}" == "1" && "${CONDA_BUILD_STATE:-}" != "TEST" ]]; then
  echo "Setting up cross-python for @CROSS_TARGET_PLATFORM@"
  _CROSS_PYTHON_DIR="${BUILD_PREFIX}/etc/conda/cross-python"

  _cross_python_fix_winsdk

  _CONDA_BACKUP_CROSS_PYTHON_PYTHON="${PYTHON:-}"
  _CONDA_BACKUP_CROSS_PYTHON_PYTHONPATH="${PYTHONPATH:-}"
  _CONDA_BACKUP_CROSS_PYTHON_LDFLAGS="${LDFLAGS:-}"
  _CONDA_BACKUP_CROSS_PYTHON_CPPFLAGS="${CPPFLAGS:-}"
  _CONDA_BACKUP_CROSS_PYTHON_CFLAGS="${CFLAGS:-}"
  _CONDA_BACKUP_CROSS_PYTHON_CXXFLAGS="${CXXFLAGS:-}"

  # activate-clang_win-64.sh runs before activate-winsdk.sh and adds the SDK
  # VFS overlay only if it already exists, so on a fresh machine (every CI run)
  # the first activation has no overlay and mixed-case SDK includes such as
  # <windows.h> fail on case-sensitive filesystems; this activation runs last
  # and adds it. Independent of the OnecoreUap workaround above (keep it when
  # that is dropped).
  _winsdk_act="${BUILD_PREFIX}/etc/conda/activate.d/activate-winsdk.sh"
  if [[ -f "${_winsdk_act}" && -n "${CONDA_BUILD_WINSDK:-}" ]]; then
    _winsdk_overlay="${CONDA_BUILD_WINSDK}/winsdk-$(sed -n 's/^WINSDK_VERSION=//p' "${_winsdk_act}")/winsdk_vfs_overlay.yaml"
    if [[ -f "${_winsdk_overlay}" ]]; then
      for _v in CPPFLAGS CFLAGS CXXFLAGS; do
        # CXXFLAGS is empty unless clangxx is active
        [[ -n "${!_v:-}" || "${_v}" != "CXXFLAGS" ]] || continue
        [[ "${!_v:-}" == *-ivfsoverlay* ]] || export "${_v}=${!_v:-} -Xclang -ivfsoverlay -Xclang ${_winsdk_overlay}"
      done
      unset _v
    fi
    unset _winsdk_overlay
  fi
  unset _winsdk_act

  # the target python cannot run on the build machine
  export PYTHON="${BUILD_PREFIX}/bin/python"

  # read by sitecustomize.py, which makes the build python report the target
  export CROSS_PYTHON_PLATFORM=@PLAT_NAME@
  export CROSS_PYTHON_EXT_SUFFIX=.cp@PY_VER_NODOT@@PY_THREAD@-@PLAT_TAG@.pyd
  export PYTHONPATH="${_CROSS_PYTHON_DIR}${PYTHONPATH:+:${PYTHONPATH}}"

  # setuptools: extension suffix, target headers and import libs
  export SETUPTOOLS_EXT_SUFFIX="${CROSS_PYTHON_EXT_SUFFIX}"
  cat > "${_CROSS_PYTHON_DIR}/distutils.cfg" <<EOF
[build_ext]
include_dirs=${PREFIX}/include
library_dirs=${PREFIX}/libs
EOF
  export DIST_EXTRA_CONFIG="${_CROSS_PYTHON_DIR}/distutils.cfg"

  # clang_win-64 puts -fuse-ld=lld only in CFLAGS, without it a link-only
  # command line spawns MSVC link.exe; pyconfig.h auto-links python3XY.lib
  # from the target's libs directory
  export LDFLAGS="${LDFLAGS:-} -fuse-ld=lld -L${PREFIX}/libs"

  # pip: install into the target prefix, not the build python's own
  export PIP_PREFIX="${PREFIX}"

  # recipe scripts call the target python by its literal path, which cannot
  # run here: put a wrapper that execs the build python in its place. Move,
  # never overwrite: the original is hardlinked to the package cache. The
  # backups go to BUILD_PREFIX because any new file in PREFIX would be packaged.
  if [[ "${PREFIX}" != "${BUILD_PREFIX}" ]]; then
    for _p in "python.exe:host-python.exe" "bin/python:host-bin-python"; do
      if [[ -e "${PREFIX}/${_p%%:*}" && ! -e "${_CROSS_PYTHON_DIR}/${_p##*:}" ]]; then
        mv -f "${PREFIX}/${_p%%:*}" "${_CROSS_PYTHON_DIR}/${_p##*:}"
        printf '#!/bin/bash\nexec "%s/bin/python" "$@"\n' "${BUILD_PREFIX}" > "${PREFIX}/${_p%%:*}"
        chmod +x "${PREFIX}/${_p%%:*}"
      fi
    done
    unset _p
  fi

  # pyo3
  export PYO3_CROSS_LIB_DIR="${PREFIX}/libs"
  export PYO3_CROSS_PYTHON_VERSION=@PY_VER@
  export PYO3_CROSS_PYTHON_IMPLEMENTATION=CPython
  echo "Finished setting up cross-python"
fi
