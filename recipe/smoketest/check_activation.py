# T2 + T3: run by the build python after the cross-python activation.
# usage: python check_activation.py <cross_target_platform>
import configparser
import os
import subprocess
import sys
import sysconfig

target = sys.argv[1]
plat_tag = target.replace("-", "_")
thread = "t" if sysconfig.get_config_var("Py_GIL_DISABLED") else ""
ext_suffix = f".cp{sys.version_info[0]}{sys.version_info[1]}{thread}-{plat_tag}.pyd"
prefix = os.environ["PREFIX"]
build_prefix = os.environ["BUILD_PREFIX"]


def check(name, got, want):
    print(f"{name}: {got!r}")
    assert got == want, f"{name}: expected {want!r}"


def same_path(a, b):
    return os.path.normcase(os.path.normpath(a)) == os.path.normcase(os.path.normpath(b))


# T2: activation contract
assert same_path(os.environ["PYTHON"], os.path.join(build_prefix, "python.exe")), os.environ["PYTHON"]
assert same_path(os.environ["PIP_PREFIX"], prefix), os.environ["PIP_PREFIX"]
assert same_path(os.environ["PYO3_CROSS_LIB_DIR"], os.path.join(prefix, "libs"))
check("PYO3_CROSS_PYTHON_VERSION", os.environ["PYO3_CROSS_PYTHON_VERSION"], f"{sys.version_info[0]}.{sys.version_info[1]}")
check("PYO3_CROSS_PYTHON_IMPLEMENTATION", os.environ["PYO3_CROSS_PYTHON_IMPLEMENTATION"], "CPython")
check("VSCMD_ARG_TGT_ARCH", os.environ["VSCMD_ARG_TGT_ARCH"], "arm64")
check("SETUPTOOLS_EXT_SUFFIX", os.environ["SETUPTOOLS_EXT_SUFFIX"], ext_suffix)

cfg = configparser.ConfigParser()
assert cfg.read(os.environ["DIST_EXTRA_CONFIG"]), os.environ["DIST_EXTRA_CONFIG"]
check("build_ext.plat_name", cfg["build_ext"]["plat_name"], target)
include_dir = cfg["build_ext"]["include_dirs"]
assert os.path.isfile(os.path.join(include_dir, "Python.h")), include_dir
assert same_path(cfg["build_ext"]["library_dirs"], os.path.join(prefix, "libs"))

# T3: the tools that read the platform agree on the target
check("sysconfig.get_platform", sysconfig.get_platform(), target)
check("EXT_SUFFIX", sysconfig.get_config_var("EXT_SUFFIX"), ext_suffix)

from packaging import tags

first = next(iter(tags.sys_tags()))
print(f"packaging first tag: {first}")
check("packaging platform", first.platform, plat_tag)

from setuptools import Distribution
from setuptools.command.build_ext import build_ext

cmd = build_ext(Distribution())
cmd.ensure_finalized()
check("setuptools ext filename", cmd.get_ext_filename("smoke"), "smoke" + ext_suffix)

out = subprocess.run(
    [sys.executable, "-m", "pip", "debug", "--verbose"],
    check=True, capture_output=True, text=True,
).stdout
assert plat_tag in out, out
assert "win_amd64" not in out, out
print("pip compatible tags: target only")
print("T2/T3 OK")
