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

    if os.name != "nt":
        # Windows target on a unix build python (clang_win-64, MSVC ABI): the
        # linux compile flags and headers of the build python must not leak in
        _include = os.path.join(os.environ["PREFIX"], "include")
        _config_vars["CCSHARED"] = ""
        _config_vars["INCLUDEPY"] = _include
        _config_vars["CONFINCLUDEPY"] = _include
        _config_vars["LDSHARED"] = os.environ.get("CC", "cc") + " -shared"

        _get_paths = sysconfig.get_paths
        _get_path = sysconfig.get_path

        def _get_paths_for_target(*args, **kwargs):
            paths = _get_paths(*args, **kwargs)
            paths.update(include=_include, platinclude=_include)
            return paths

        def _get_path_for_target(name, *args, **kwargs):
            if name in ("include", "platinclude"):
                return _include
            return _get_path(name, *args, **kwargs)

        sysconfig.get_paths = _get_paths_for_target
        sysconfig.get_path = _get_path_for_target

        # pip installs with the build python's install scheme, posix_prefix on
        # linux, which puts packages in lib/pythonX.Y/site-packages; a Windows
        # python expects Lib/site-packages and Scripts
        if "nt" in sysconfig._INSTALL_SCHEMES:
            _get_preferred_scheme = sysconfig.get_preferred_scheme

            def _get_preferred_scheme_for_target(key):
                if key in ("prefix", "home"):
                    return "nt"
                if key == "user" and "nt_user" in sysconfig._INSTALL_SCHEMES:
                    return "nt_user"
                return _get_preferred_scheme(key)

            sysconfig.get_preferred_scheme = _get_preferred_scheme_for_target
            sysconfig.get_default_scheme = lambda: "nt"

        # packaging takes the macOS tags from platform.mac_ver() and ignores
        # sysconfig on a darwin build python, and pip vendors its own copy; pin
        # platform_tags (a module global, looked up at call time) to the target
        import importlib.machinery
        import sys

        _tag = _platform.replace("-", "_").replace(".", "_")

        class _PlatformTagsFinder:
            @staticmethod
            def find_spec(name, path=None, target=None):
                if name not in ("packaging.tags", "pip._vendor.packaging.tags"):
                    return None
                spec = importlib.machinery.PathFinder.find_spec(name, path, target)
                if spec is None or spec.loader is None:
                    return None
                _exec_module = spec.loader.exec_module

                def exec_module(module):
                    _exec_module(module)
                    module.platform_tags = lambda: iter([_tag])

                spec.loader.exec_module = exec_module
                return spec

        sys.meta_path.insert(0, _PlatformTagsFinder)
