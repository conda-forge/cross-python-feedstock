#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define MAX_PATHLEN 1024

/*
  This program is a simple binary shim that replaces the following shell script:

  #!/bin/bash
  exec $PREFIX/bin/python "$@"

  This is needed because MacOS security protections won't let a shell script
  be the interpreter for another shell script in the shebang.  With this
  shim in place, scripts like cython and f2py can bounce through
  this executable instead of bouncing through a bash script.
*/

int main(int argc, char **argv) {
    char *prefix;
    char cross_py[MAX_PATHLEN];

    // Get the PREFIX environment variable.
    prefix = getenv("PREFIX");

    if (prefix == NULL) {
        fprintf(stderr, "Could not find PREFIX environment variable.\n");
        return -1;
    }

    // The cross-python executable we want to run lives in $PREFIX/bin/python
    snprintf(cross_py, MAX_PATHLEN, "%s/bin/python", prefix);

    // Now exec the cross-python, with the given arguments.
    execv(cross_py, argv);
}
