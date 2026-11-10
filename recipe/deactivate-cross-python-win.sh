#!/bin/bash

if [[ "${CONDA_BUILD:-0}" == "1" && "${CONDA_BUILD_STATE:-}" != "TEST" && -n "${CROSS_PYTHON_PLATFORM:-}" ]]; then
  _CROSS_PYTHON_DIR="${BUILD_PREFIX}/etc/conda/cross-python"

  if [[ "${PREFIX}" != "${BUILD_PREFIX}" ]]; then
    for _p in "python.exe:host-python.exe" "bin/python:host-bin-python"; do
      if [[ -e "${_CROSS_PYTHON_DIR}/${_p##*:}" ]]; then
        rm -f "${PREFIX}/${_p%%:*}"
        mv -f "${_CROSS_PYTHON_DIR}/${_p##*:}" "${PREFIX}/${_p%%:*}"
      fi
    done
    unset _p
  fi

  export PYTHON="${_CONDA_BACKUP_CROSS_PYTHON_PYTHON}"
  export PYTHONPATH="${_CONDA_BACKUP_CROSS_PYTHON_PYTHONPATH}"
  export LDFLAGS="${_CONDA_BACKUP_CROSS_PYTHON_LDFLAGS}"
  export CPPFLAGS="${_CONDA_BACKUP_CROSS_PYTHON_CPPFLAGS}"
  export CFLAGS="${_CONDA_BACKUP_CROSS_PYTHON_CFLAGS}"
  export CXXFLAGS="${_CONDA_BACKUP_CROSS_PYTHON_CXXFLAGS}"
  [[ -n "${PYTHON}" ]] || unset PYTHON
  [[ -n "${PYTHONPATH}" ]] || unset PYTHONPATH
  [[ -n "${LDFLAGS}" ]] || unset LDFLAGS
  [[ -n "${CPPFLAGS}" ]] || unset CPPFLAGS
  [[ -n "${CFLAGS}" ]] || unset CFLAGS
  [[ -n "${CXXFLAGS}" ]] || unset CXXFLAGS
  unset _CONDA_BACKUP_CROSS_PYTHON_PYTHON
  unset _CONDA_BACKUP_CROSS_PYTHON_PYTHONPATH
  unset _CONDA_BACKUP_CROSS_PYTHON_LDFLAGS
  unset _CONDA_BACKUP_CROSS_PYTHON_CPPFLAGS
  unset _CONDA_BACKUP_CROSS_PYTHON_CFLAGS
  unset _CONDA_BACKUP_CROSS_PYTHON_CXXFLAGS

  unset CROSS_PYTHON_PLATFORM
  unset CROSS_PYTHON_EXT_SUFFIX
  unset SETUPTOOLS_EXT_SUFFIX
  unset DIST_EXTRA_CONFIG
  unset PIP_PREFIX
  unset PYO3_CROSS_LIB_DIR
  unset PYO3_CROSS_PYTHON_VERSION
  unset PYO3_CROSS_PYTHON_IMPLEMENTATION
  unset _CROSS_PYTHON_DIR
fi
