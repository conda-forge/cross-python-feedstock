# Installed by cross-python for Windows targets. The cross-python activation
# puts this directory on PYTHONPATH, so the build python imports it at startup
# and reports the target platform; setuptools, pip and packaging then build
# and accept wheels for the target instead of the build machine.
import os

_platform = os.environ.get("CROSS_PYTHON_PLATFORM")
if _platform:
    import sysconfig

    _ext_suffix = os.environ["CROSS_PYTHON_EXT_SUFFIX"]
    # get_config_vars() returns the cached dict that get_config_var() reads
    _config_vars = sysconfig.get_config_vars()
    _config_vars["EXT_SUFFIX"] = _ext_suffix
    # ".cp314-win_arm64.pyd" -> "cp314-win_arm64"
    _config_vars["SOABI"] = _ext_suffix[1:].rsplit(".", 1)[0]
    sysconfig.get_platform = lambda: _platform
