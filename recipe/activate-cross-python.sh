#!/bin/bash

if [[ "${CONDA_BUILD:-0}" == "1" && "${CONDA_BUILD_STATE}" != "TEST" ]]; then
  _CONDA_PYTHON_SYSCONFIGDATA_NAME_BACKUP=${_CONDA_PYTHON_SYSCONFIGDATA_NAME}
  if [ -d "$PREFIX/lib_pypy" ]; then
    find "$PREFIX/lib_pypy/" -name "_sysconfigdata*.py" -not -name "_sysconfigdata.py" -type f -exec rm -f {} +
    sysconfigdata_fn="$PREFIX/lib_pypy/_sysconfigdata.py"
  else
    find "$PREFIX/lib/" -name "_sysconfigdata*.py" -not -name ${_CONDA_PYTHON_SYSCONFIGDATA_NAME} -type f -exec rm -f {} +
    sysconfigdata_fn="$PREFIX/lib/python$PY_VER/${_CONDA_PYTHON_SYSCONFIGDATA_NAME_BACKUP}.py"
  fi
  unset _CONDA_PYTHON_SYSCONFIGDATA_NAME
  PY_VER=$($BUILD_PREFIX/bin/python -c "import sys; print('{}.{}'.format(*sys.version_info[:2]))")
  if [[ ! -d $BUILD_PREFIX/venv ]]; then
    $BUILD_PREFIX/bin/python -m crossenv $PREFIX/bin/python \
        --sysroot $CONDA_BUILD_SYSROOT \
        --without-pip $BUILD_PREFIX/venv \
        --sysconfigdata-file "$sysconfigdata_fn" \
        --cc $CC \
        --cxx $CXX

    # pypy generates _sysconfigdata.py dynamically so fix it up
    if [ -d "$PREFIX/lib_pypy" ]; then
      sed -i.bak "s@x86_64-linux@linux@g" "$BUILD_PREFIX/venv/lib/_sysconfigdata.py"
      diff "$BUILD_PREFIX/venv/lib/_sysconfigdata.py.bak" "$BUILD_PREFIX/venv/lib/_sysconfigdata.py" || true
      # Also fix the PYTHONPATH in the shell wrapper
      stdlib=$(pypy -c "import sysconfig; print(sysconfig.get_path('stdlib'))")
      sed -i.bak "s@$stdlib'@$stdlib', '$PREFIX/lib_pypy'@g" "$BUILD_PREFIX/venv/cross/bin/python"
      diff "$BUILD_PREFIX/venv/cross/bin/python.bak" "$BUILD_PREFIX/venv/cross/bin/python" || true
    fi

    # For recipes using {{ PYTHON }}
    cp $BUILD_PREFIX/venv/cross/bin/python $PREFIX/bin/python

    # undo symlink
    rm $BUILD_PREFIX/venv/build/bin/python
    cp $BUILD_PREFIX/bin/python $BUILD_PREFIX/venv/build/bin/python

    # For recipes using python.app
    if [[ -f "$PREFIX/python.app/Contents/MacOS/python" ]]; then
      cp $PREFIX/bin/python $PREFIX/python.app/Contents/MacOS/python
    fi

    # For recipes looking at python on PATH
    rm $BUILD_PREFIX/bin/python
    echo "#!/bin/bash" > $BUILD_PREFIX/bin/python
    echo "exec $PREFIX/bin/python \"\$@\"" >> $BUILD_PREFIX/bin/python
    chmod +x $BUILD_PREFIX/bin/python

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
fi
