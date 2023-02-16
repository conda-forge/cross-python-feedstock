#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define MAX_PATHLEN 1024

/*
  This program is a simple binary shim that replaces the following shell script:

  #!/bin/bash
  exec $PREFIX/bin/python "$@"

  with a slightly updated version that is the equivalent to the more direct

  #!/bin/bash
  exec $BUILD_PREFIX/venv/build/bin/python "$@"

  This is needed because MacOS security protections won't let a shell script
  be the interpreter for another shell script in the shebang.  With this
  shim in place, scripts like cython and f2py can bounce through
  this executable instead of bouncing through a bash script.
*/

int main(int argc, char **argv) {
    char cross_py[MAX_PATHLEN] = "@PREFIX@/venv/bin/cross-python";
    // Now exec the cross-python, with the given arguments.
    execv(cross_py, argv);
}
