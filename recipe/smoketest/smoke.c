/* T4: compile-only probe for the target compiler; never linked. */
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static struct PyModuleDef smoke_module = {
    PyModuleDef_HEAD_INIT, "smoke", NULL, -1, NULL,
};

PyMODINIT_FUNC PyInit_smoke(void) {
    return PyModule_Create(&smoke_module);
}
