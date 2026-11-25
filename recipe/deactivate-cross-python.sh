#!/bin/bash

if [[ "${CONDA_BUILD:-0}" == "1" && "${CONDA_BUILD_STATE}" != "TEST" ]]; then
  unset PYTHONPATH
  if [[ "${_CONDA_BACKUP_PYTHONPATH}" != "" ]]; then
    export PYTHONPATH=${_CONDA_BACKUP_PYTHONPATH}
  fi
  if [[ -n "${_CONDA_BACKUP_CROSS_PYTHON_CMAKE_ARGS+x}" ]]; then
    export CMAKE_ARGS="${_CONDA_BACKUP_CROSS_PYTHON_CMAKE_ARGS}"
    unset _CONDA_BACKUP_CROSS_PYTHON_CMAKE_ARGS
  fi
fi
