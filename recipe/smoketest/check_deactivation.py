# T2: run after the cross-python deactivation; the build python is itself again.
import os
import sysconfig

for var in (
    "CROSS_PYTHON_PLATFORM",
    "CROSS_PYTHON_EXT_SUFFIX",
    "DIST_EXTRA_CONFIG",
    "PIP_PREFIX",
    "SETUPTOOLS_EXT_SUFFIX",
    "PYO3_CROSS_LIB_DIR",
    "_CONDA_BACKUP_CROSS_PYTHON_PATH",
):
    assert var not in os.environ, var
assert os.environ["PATH"] == os.environ["_SMOKE_PATH"], "PATH not restored"
assert os.environ.get("VSCMD_ARG_TGT_ARCH", "") == os.environ.get("_SMOKE_VSCMD", ""), "VSCMD_ARG_TGT_ARCH not restored"
assert "cross-python" not in os.environ.get("PYTHONPATH", ""), os.environ.get("PYTHONPATH")
assert sysconfig.get_platform() == "win-amd64", sysconfig.get_platform()
print("deactivation OK")
