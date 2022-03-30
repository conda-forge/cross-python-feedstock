#!/bin/bash

if [[ "${CONDA_BUILD:-0}" == "1" && "${CONDA_BUILD_STATE}" != "TEST" ]]; then
  echo "Setting up cross-python"
  PY_VER=$($BUILD_PREFIX/bin/python -c "import sys; print('{}.{}'.format(*sys.version_info[:2]))")
  if [ -d "$PREFIX/lib_pypy" ]; then
    sysconfigdata_fn=$(find "$PREFIX/lib_pypy/" -name "_sysconfigdata_*.py" -type f)
  elif [ -d "$PREFIX/lib/pypy$PY_VER" ]; then
    sysconfigdata_fn=$(find "$PREFIX/lib/pypy$PY_VER/" -name "_sysconfigdata_*.py" -type f)
  else
    find "$PREFIX/lib/" -name "_sysconfigdata*.py" -not -name ${_CONDA_PYTHON_SYSCONFIGDATA_NAME}.py -type f -exec rm -f {} +
    sysconfigdata_fn="$PREFIX/lib/python$PY_VER/${_CONDA_PYTHON_SYSCONFIGDATA_NAME}.py"
  fi
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

    # For recipes using {{ PYTHON }}
    cp $BUILD_PREFIX/venv/cross/bin/python $PREFIX/bin/python

    # don't set LIBRARY_PATH
    # See https://github.com/conda-forge/matplotlib-feedstock/pull/309#issuecomment-972213735
    sed -i 's/extra_envs = .*/extra_envs = []/g' $PREFIX/bin/python        || true
    sed -i 's/extra_envs = .*/extra_envs = []/g' $PREFIX/bin/python$PY_VER || true

    # rewrite symlink $BUILD_PREFIX/bin/python -> $BUILD_PREFIX/venv/build/bin/python
    # to a symlink $BUILD_PREFIX/bin/python3.x -> $BUILD_PREFIX/venv/build/bin/python
    rm $BUILD_PREFIX/venv/build/bin/python
    ln -sf $BUILD_PREFIX/bin/$(readlink $BUILD_PREFIX/bin/python) $BUILD_PREFIX/venv/build/bin/python

    # For recipes looking at python on PATH
    rm $BUILD_PREFIX/bin/python
    echo "#!/bin/bash" > $BUILD_PREFIX/bin/python
    echo "exec $PREFIX/bin/python \"\$@\"" >> $BUILD_PREFIX/bin/python
    chmod +x $BUILD_PREFIX/bin/python

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
    sed -i.bak "s@$BUILD_PREFIX/venv/lib@$BUILD_PREFIX/venv/lib', '$BUILD_PREFIX/venv/lib/python$PY_VER/site-packages@g" $PYTHON
    rm -f $PYTHON.bak

    if [[ "${PYTHONPATH}" != "" ]]; then
      _CONDA_BACKUP_PYTHONPATH=${PYTHONPATH}
    fi
  fi
  unset sysconfigdata_fn
  export PYTHONPATH=$BUILD_PREFIX/venv/lib/python$PY_VER/site-packages
  echo "Finished setting up cross-python"
fi
