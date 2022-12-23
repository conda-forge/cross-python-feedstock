#!/bin/bash

if [[ "${CONDA_BUILD:-0}" == "1" && "${CONDA_BUILD_STATE}" != "TEST" ]]; then
  echo "Setting up cross-python"

  PY_VER=$($BUILD_PREFIX/bin/python -c "import sys; print('{}.{}'.format(*sys.version_info[:2]))")

  if [ -d "$PREFIX/lib_pypy" ]; then
    sysconfigdata_fn=$(find "$PREFIX/lib_pypy/" -name "_sysconfigdata_*.py" -type f)
    export PYO3_CROSS_LIB_DIR=$PREFIX/lib_pypy
    export PYO3_CROSS_PYTHON_IMPLEMENTATION=PyPy
  elif [ -d "$PREFIX/lib/pypy$PY_VER" ]; then
    sysconfigdata_fn=$(find "$PREFIX/lib/pypy$PY_VER/" -name "_sysconfigdata_*.py" -type f)
    export PYO3_CROSS_LIB_DIR=$PREFIX/lib/pypy$PY_VER
    export PYO3_CROSS_PYTHON_IMPLEMENTATION=PyPy
  else
    find "$PREFIX/lib/" -name "_sysconfigdata*.py" -not -name ${_CONDA_PYTHON_SYSCONFIGDATA_NAME}.py -type f -exec rm -f {} +
    sysconfigdata_fn="$PREFIX/lib/python$PY_VER/${_CONDA_PYTHON_SYSCONFIGDATA_NAME}.py"
    export PYO3_CROSS_LIB_DIR=$PREFIX/lib/python$PY_VER
    export PYO3_CROSS_PYTHON_IMPLEMENTATION=CPython
  fi

  export PYO3_CROSS_INCLUDE_DIR=$PREFIX/include
  export PYO3_CROSS_PYTHON_VERSION=$PY_VER
  unset _CONDA_PYTHON_SYSCONFIGDATA_NAME

  if [[ ! -d $BUILD_PREFIX/venv ]]; then
    $BUILD_PREFIX/bin/python -m crossenv $PREFIX/bin/python \
        --sysroot $CONDA_BUILD_SYSROOT \
        --without-pip $BUILD_PREFIX/venv \
        --sysconfigdata-file "$sysconfigdata_fn" \
        --cc ${CC} \
        --cxx ${CXX:-c++}

    # Undo cross-python's changes
    # See https://github.com/conda-forge/h5py-feedstock/pull/104
    rm -rf $BUILD_PREFIX/venv/lib/$(basename $sysconfigdata_fn)
    cp $sysconfigdata_fn $BUILD_PREFIX/venv/lib/$(basename $sysconfigdata_fn)

    # We expose the "cross" python wrapper script as both $PREFIX/bin/python and
    # $BUILD_PREFIX/bin/python. The problem (see #64) is that on macOS, you can't
    # have the interpreter of a shebang script be an interpreted script itself,
    # and packages like Cython end up using scripts that try to do that. So,
    # this package provides a shim that delegates to the wrapper.

    # crossenv sets up `$BUILD_PREFIX/venv/build/bin/python` as a symlink to
    # `$BUILD_PREFIX/bin/python`. That won't work for us since we're about to
    # replace `$BUILD_PREFIX/bin/python` with the shim. Replace it with a link
    # to the versioned binary, which will remain untouched. Note that
    # `venv/build/bin/python` should continue to exist because it's referenced
    # by the wrapper script (although we could potentially rewrite it out). The
    # shim also needs there to be a well-known name for the true Python binary,
    # and it doesn't know $PY_VER at build time.
    rm $BUILD_PREFIX/venv/build/bin/python
    ln -sf $BUILD_PREFIX/bin/$(readlink $BUILD_PREFIX/bin/python) $BUILD_PREFIX/venv/build/bin/python

    # Now back up the wrapper (we delete venv/cross below) ...
    cp $BUILD_PREFIX/venv/cross/bin/python $BUILD_PREFIX/bin/_cross_python_wrapper.py

    # ... and customize it: Don't set LIBRARY_PATH
    # See https://github.com/conda-forge/matplotlib-feedstock/pull/309#issuecomment-972213735
    sed -i 's/extra_envs = .*/extra_envs = []/g' $BUILD_PREFIX/bin/_cross_python_wrapper.py || true

    # For recipes using {{ PYTHON }}, we clobber $PREFIX/bin/python.
    # Remove the file first as it might be a hardlink and make sure to resolve symlinks
    # Use the real $BUILD_PREFIX Python to get the real path before blowing it away!
    python_real_path=$($BUILD_PREFIX/bin/python -c "import os; print(os.path.realpath('$PREFIX/bin/python'))")
    rm $python_real_path
    cp -p $BUILD_PREFIX/bin/_cross_python_launcher_shim $python_real_path
    unset python_real_path

    # Now we can blow away the $BUILD_PREFIX Python and unstall the shim for
    # recipes that look for `python` on PATH.
    rm $BUILD_PREFIX/bin/python
    cp -p $BUILD_PREFIX/bin/_cross_python_launcher_shim $BUILD_PREFIX/bin/python

    if [[ -f "$PREFIX/bin/pypy" ]]; then
      rm -rf $BUILD_PREFIX/venv/lib/pypy$PY_VER
      mkdir -p $BUILD_PREFIX/venv/lib/python$PY_VER
      ln -s $BUILD_PREFIX/venv/lib/python$PY_VER $BUILD_PREFIX/venv/lib/pypy$PY_VER
    fi

    rm -rf $BUILD_PREFIX/venv/cross

    if [[ -d "$PREFIX/lib/python$PY_VER/site-packages/" ]]; then
      find $PREFIX/lib/python$PY_VER/site-packages/ -name "*.so" -exec rm {} \;
      find $PREFIX/lib/python$PY_VER/site-packages/ -name "*.dylib" -exec rm {} \;
      rsync -a -I $PREFIX/lib/python$PY_VER/site-packages/ $BUILD_PREFIX/lib/python$PY_VER/site-packages/
      rm -rf $PREFIX/lib/python$PY_VER/site-packages
      mkdir $PREFIX/lib/python$PY_VER/site-packages
    fi

    rm -rf $BUILD_PREFIX/venv/lib/python$PY_VER/site-packages
    ln -s $BUILD_PREFIX/lib/python$PY_VER/site-packages $BUILD_PREFIX/venv/lib/python$PY_VER/site-packages

    # More customization of the wrapper.
    sed -i.bak \
      "s@$BUILD_PREFIX/venv/lib@$BUILD_PREFIX/venv/lib', '$BUILD_PREFIX/lib/python$PY_VER/lib-dynload', '$BUILD_PREFIX/venv/lib/python$PY_VER/site-packages@g" \
      $BUILD_PREFIX/bin/_cross_python_wrapper.py
    rm -f $BUILD_PREFIX/bin/_cross_python_wrapper.py.bak

    if [[ "$PY_VER" == "3.1"* && "$PY_VER" != "3.10" ]]; then
      # python 3.11 and up uses frozen modules to import site.py, so the custom doesn't get
      # picked up.
      ln -sf $BUILD_PREFIX/venv/lib/site.py $BUILD_PREFIX/venv/lib/sitecustomize.py
    fi

    if [[ "${PYTHONPATH}" != "" ]]; then
      _CONDA_BACKUP_PYTHONPATH=${PYTHONPATH}
    fi
  fi

  unset sysconfigdata_fn
  export PYTHONPATH=$BUILD_PREFIX/venv/lib/python$PY_VER/site-packages
  echo "Finished setting up cross-python"
fi
