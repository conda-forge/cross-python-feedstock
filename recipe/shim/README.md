# cross-python launcher shim

See <https://github.com/conda-forge/cross-python-feedstock/issues/64>.

In the conda-forge build ecosystem, the [cross-python] helper package contains
scripts that use [crossenv] to set up a Python environment that can be used for
cross-compiling Python binary modules. The cross-compilation setup turns the
`python` executable into a wrapper script, and this causes problems on MacOS
because it does not allow “shebang” interpreters (in `#! /path/to/program`
lines) to themselves be interpreted scripts. Certain packages like [Cython]
involve scripts that point to the `python` executable, leading to failures.

[cross-python]: https://github.com/conda-forge/cross-python-feedstock/
[crossenv]: https://crossenv.readthedocs.io/
[Cython]: https://cython.org

This package provides a small binary shim program that invokes the desired
script. The cross-python activation scripts copy it to the necessary location(s)
so that `python` invokes the desired wrapper, while remaining a binary so that
it can be used as a shebang interpreter.
