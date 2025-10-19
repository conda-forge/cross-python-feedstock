#!/bin/bash

if [[ "${CONDA_BUILD:-0}" == "1" && "${CONDA_BUILD_STATE}" != "TEST" ]]; then
  echo "Setting up cross-python"
  PY_VER=$($BUILD_PREFIX/bin/python -c "import sys; print('{}.{}'.format(*sys.version_info[:2]))")
  if [ -d "$PREFIX/lib_pypy" ]; then
    sysconfigdata_fn=$(find "$PREFIX/lib_pypy/" -name "_sysconfigdata_*.py" -type f)
    export PYO3_CROSS_LIB_DIR=$PREFIX/lib_pypy
    export PYO3_CROSS_PYTHON_IMPLEMENTATION=PyPy
  elif [ -d "$PREFIX/lib/pypy@PY_VER@" ]; then
    sysconfigdata_fn=$(find "$PREFIX/lib/pypy@PY_VER@/" -name "_sysconfigdata_*.py" -type f)
    export PYO3_CROSS_LIB_DIR=$PREFIX/lib/pypy@PY_VER@
    export PYO3_CROSS_PYTHON_IMPLEMENTATION=PyPy
  else
    # sysconfigdata_fn=$(find "$PREFIX/lib/python@PY_VER@@PY_THREAD@/" -name "_sysconfigdata_*.py.orig" -type f)
    # sysconfigdata_fn=${sysconfigdata_fn%.orig}
    sysconfigdata_fn="$PREFIX/lib/python@PY_VER@@PY_THREAD@/@_CONDA_PYTHON_SYSCONFIGDATA_NAME@.py"
    find "$PREFIX/lib/" -name "_sysconfigdata*.py" -not -name $(basename ${sysconfigdata_fn}) -type f -exec rm -f {} +
    export PYO3_CROSS_LIB_DIR=$PREFIX/lib/python@PY_VER@@PY_THREAD@
    export PYO3_CROSS_PYTHON_IMPLEMENTATION=CPython
  fi
  export PYO3_CROSS_INCLUDE_DIR=$PREFIX/include
  export PYO3_CROSS_PYTHON_VERSION=@PY_VER@
  unset _CONDA_PYTHON_SYSCONFIGDATA_NAME
  if [[ ! -d $BUILD_PREFIX/venv ]]; then
    case "${target_platform}" in
      *-64)
        machine=x86_64
        ;;
      *)
        machine=${target_platform#*-}
        ;;
    esac

    if [[ "${CONDA_BUILD_SYSROOT:-}" != "" ]]; then
      _SYSROOT_ARG="--sysroot $CONDA_BUILD_SYSROOT"
    fi
    $BUILD_PREFIX/bin/python -m crossenv $PREFIX/bin/python \
        ${_SYSROOT_ARG:-} \
        --without-pip $BUILD_PREFIX/venv \
        --sysconfigdata-file "$sysconfigdata_fn" \
        --machine ${machine} \
        --cc ${CC:-@CC@} \
        --cxx ${CXX:-@CXX@}

    # Undo cross-python's changes
    # See https://github.com/conda-forge/h5py-feedstock/pull/104
    rm -rf $BUILD_PREFIX/venv/lib/$(basename $sysconfigdata_fn)
    cp $sysconfigdata_fn $BUILD_PREFIX/venv/lib/$(basename $sysconfigdata_fn)

    cp $BUILD_PREFIX/venv/cross/bin/python $BUILD_PREFIX/venv/bin/cross-python
    # don't set LIBRARY_PATH
    # See https://github.com/conda-forge/matplotlib-feedstock/pull/309#issuecomment-972213735
    sed -i 's/extra_envs = .*/extra_envs = []/g' $BUILD_PREFIX/venv/bin/cross-python || true
    # set sys.executable
    sed -i "s@import sys@import sys\nsys.argv[0] = '$PREFIX/bin/python'@g" $BUILD_PREFIX/venv/bin/cross-python
    # Load BUILD_PREFIX's packages first
    sed -i.bak "s@$BUILD_PREFIX/venv/lib@$BUILD_PREFIX/venv/lib', '$BUILD_PREFIX/lib/python@PY_VER@@PY_THREAD@/lib-dynload', '$BUILD_PREFIX/venv/lib/python@PY_VER@@PY_THREAD@/site-packages@g" $BUILD_PREFIX/venv/bin/cross-python

    # For recipes using {{ PYTHON }}
    # Install the binary shim which execs $BUILD_PREFIX/venv/bin/cross-python
    # Remove the file first as it might be a hardlink and make sure to resolve symlinks
    python_real_path=$($BUILD_PREFIX/bin/python -c "import os; print(os.path.realpath('$PREFIX/bin/python'))")
    rm $python_real_path
    if [ -d "$PREFIX/lib/pypy@PY_VER@" ]; then
        # TODO: Remove this when pypy supports PYTHONHOME env variable
        cp $BUILD_PREFIX/venv/bin/cross-python $python_real_path
    else
        cp $BUILD_PREFIX/bin/cross_python_shim $python_real_path
    fi

    # rewrite symlink $BUILD_PREFIX/bin/python -> $BUILD_PREFIX/venv/build/bin/python
    # to a symlink $BUILD_PREFIX/bin/python3.x -> $BUILD_PREFIX/venv/build/bin/python
    rm $BUILD_PREFIX/venv/build/bin/python
    ln -sf $BUILD_PREFIX/bin/$(readlink $BUILD_PREFIX/bin/python) $BUILD_PREFIX/venv/build/bin/python

    # For recipes looking at python on PATH
    # Install the binary shim which execs $BUILD_PREFIX/venv/build/bin/python
    rm $BUILD_PREFIX/bin/python
    cp $BUILD_PREFIX/bin/cross_python_shim $BUILD_PREFIX/bin/python

    if [[ -f "$PREFIX/bin/pypy" ]]; then
      rm -rf $BUILD_PREFIX/venv/lib/pypy@PY_VER@
      mkdir -p $BUILD_PREFIX/venv/lib/python@PY_VER@
      ln -s $BUILD_PREFIX/venv/lib/python@PY_VER@ $BUILD_PREFIX/venv/lib/pypy@PY_VER@
    fi

    rm -rf $BUILD_PREFIX/venv/cross
    if [[ -d "$PREFIX/lib/python@PY_VER@@PY_THREAD@/site-packages/" ]]; then
      rsync -a --exclude="*.so" --exclude="*.dylib" -I $PREFIX/lib/python@PY_VER@@PY_THREAD@/site-packages/ $BUILD_PREFIX/lib/python@PY_VER@@PY_THREAD@/site-packages/
    fi
    rm -rf $BUILD_PREFIX/venv/lib/python@PY_VER@@PY_THREAD@/site-packages
    ln -s $BUILD_PREFIX/lib/python@PY_VER@@PY_THREAD@/site-packages $BUILD_PREFIX/venv/lib/python@PY_VER@@PY_THREAD@/site-packages
    # if nogil-specific SP_DIR does not exist yet (either as dir or symlink), create a symlink to
    # the one without the "t" suffix (which will always be used for noarch packages, for example)
    if [[ "@PY_THREAD@" == "t" && ! -e $BUILD_PREFIX/venv/lib/python@PY_VER@@PY_THREAD@/site-packages ]]; then
      ln -s $BUILD_PREFIX/lib/python@PY_VER@/site-packages/* $BUILD_PREFIX/venv/lib/python@PY_VER@@PY_THREAD@/site-packages/
    fi
    if [[ "@PY_VER@" == "3.1"* && "@PY_VER@" != "3.10" ]]; then
      # python 3.11 and up uses frozen modules to import site.py, so the custom doesn't get
      # picked up.
      ln -sf $BUILD_PREFIX/venv/lib/site.py $BUILD_PREFIX/venv/lib/sitecustomize.py
    fi

    unset python_real_path

    if [[ "${PYTHONPATH}" != "" ]]; then
      _CONDA_BACKUP_PYTHONPATH=${PYTHONPATH}
    fi

    if [[ -f "${BUILD_PREFIX}/meson_cross_file.txt" && (-f "${BUILD_PREFIX}/bin/meson" || -f "${PREFIX}/bin/meson") ]]; then
      if ! grep -q "python =" "${BUILD_PREFIX}/meson_cross_file.txt"; then
        if [[ -f "${SRC_DIR}/conda_build.sh" ]]; then
          if grep -q "meson_cross_file" "${SRC_DIR}/conda_build.sh"; then
            echo "WARNING: Not adding python to meson_cross_file.txt as that file is being manipulated by the recipe"
          else
            echo "Adding python to meson_cross_file.txt."
            echo "python = '${PREFIX}/bin/python'" >> ${BUILD_PREFIX}/meson_cross_file.txt
          fi
        else
          echo "WARNING: Adding python to meson_cross_file.txt"
          echo "python = '${PREFIX}/bin/python'" >> ${BUILD_PREFIX}/meson_cross_file.txt
        fi
      fi
    fi
  fi
  unset sysconfigdata_fn
  export PYTHONPATH=$BUILD_PREFIX/venv/lib/python@PY_VER@@PY_THREAD@/site-packages
  echo "Finished setting up cross-python"
fi
